import json, sys, numpy as np
from PIL import Image, ImageDraw
d=json.load(open('../assets/track/city17_circuit.json'))
t=d['terrain']; H=np.fromfile('../assets/track/city17_circuit_height.bin',dtype=np.float32).reshape(t['nz'],t['nx'])
sea=d['sea_level']
img=np.zeros(H.shape+(3,),np.uint8)
land=(H>sea)
v=np.clip((H-sea)/100,0,1)
img[...,0]=np.where(land, 60+v*190, 20); img[...,1]=np.where(land,90+v*160,60); img[...,2]=np.where(land,50+v*120,130)
im=Image.fromarray(img).resize((t['nx']*2,t['nz']*2))
dr=ImageDraw.Draw(im)
def px(p): return ((p[0]-t['x0'])/t['cell']*2,(p[2]-t['z0'])/t['cell']*2)
c=d['path']['center']; th=d['path']['theme']; gap=d['path']['gap']
col={'city':(230,230,230),'coast':(250,200,60),'dirt':(160,100,40),'canal':(80,200,255)}
for i in range(len(c)):
  a=px(c[i]); b=px(c[(i+1)%len(c)])
  dr.line([a,b],fill=(255,0,0) if gap[i] else col[th[i]],width=5)
for p in d['path']['line'][::2]:
  x,y=px(p); dr.point((x,y),fill=(255,0,255))
for p in d['props']:
  x,y=px(p['pos']); dr.rectangle([x-1,y-1,x+1,y+1],fill=(0,0,0) if p['tag']!='building' else (255,128,0))
for p in d['item_boxes']:
  x,y=px(p); dr.ellipse([x-3,y-3,x+3,y+3],fill=(0,255,0))
for g in d['grid']:
  x,y=px(g['pos']); dr.ellipse([x-3,y-3,x+3,y+3],fill=(0,0,255))
im.save(sys.argv[1])
print(sum(1 for p in d['props'] if p['tag']=='building'), 'buildings')
