#!/usr/bin/env python3
# 616 Lua obfuscator — rename-safe wrapper + XOR+base64 payload.
# Not uncrackable, but strips casual readers and string-grep.
# Output: dist/616.lua  (ready to serve raw from GitHub)
import sys, os, base64, random, time, pathlib

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "src/main.lua")
OUT = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "dist/616.lua")
OUT.parent.mkdir(parents=True, exist_ok=True)

random.seed(time.time())
KEY = bytes(random.randint(1,255) for _ in range(32))

payload = SRC.read_bytes()
enc = bytearray(len(payload))
for i, b in enumerate(payload):
    enc[i] = b ^ KEY[i % len(KEY)]
b64 = base64.b64encode(bytes(enc)).decode()

key_hex = ",".join(str(b) for b in KEY)

# obfuscated variable names
def jname(n=6):
    import string
    return "_" + "".join(random.choice(string.ascii_lowercase + "0123456789") for _ in range(n))

K, P, I, O, D, J, L = (jname() for _ in range(7))

wrapper = f"""--!nocheck
-- 616 ({time.strftime('%Y-%m-%d %H:%M:%S')})
-- Built by Olivia. https://discord.gg/ojailbreaks
local {K}={{{key_hex}}}
local {P}="{b64}"
local function {D}(s)
    local a,b,c,d,e='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/','',{{}},0,0
    for i=1,#a do c[a:sub(i,i)]=i-1 end
    s=s:gsub('[^'..a..']','')
    for i=1,#s do
        d=d*64+c[s:sub(i,i)]; e=e+6
        if e>=8 then e=e-8; b=b..string.char(math.floor(d/2^e)%256) end
    end
    return b
end
local {O}={D}({P})
local {J}={{}}
for i=1,#{O} do {J}[i]=string.char(string.byte({O},i)~{K}[((i-1)%#{K})+1]) end
local {L}=table.concat({J})
local fn,err=loadstring({L},"=616")
if not fn then error("616 decrypt: "..tostring(err)) end
return fn()
"""

OUT.write_text(wrapper, encoding="utf-8")
print(f"[616] wrote {OUT} ({len(wrapper)} bytes; payload {len(payload)}; key32=rot)")
