import sys,struct
def uleb(b,o):
    r=s=0
    while True:
        x=b[o];o+=1;r|=(x&0x7f)<<s;s+=7
        if x<0x80:return r,o
out=open(sys.argv[1],'w',encoding='utf-8')
for p in sys.argv[2:]:
    b=open(p,'rb').read()
    n,off=struct.unpack_from('<II',b,0x38)
    for i in range(n):
        so=struct.unpack_from('<I',b,off+4*i)[0]
        _,o=uleb(b,so);e=b.index(0,o)
        out.write(b[o:e].decode('utf-8','replace').replace('\n','\\n')+'\n')
