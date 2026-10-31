# Seedance 2.5 por API de BytePlus con la key del pod. Genera en la nube: no usa la GPU.
import base64,io,json,os,time,urllib.error,urllib.request
import folder_paths
from PIL import Image,ImageOps
API="https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks"
MIME={".mp4":"video/mp4",".mov":"video/quicktime"}
def call(url,body=None):
    r=urllib.request.Request(url,json.dumps(body).encode() if body else None,{"Content-Type":"application/json","Authorization":"Bearer "+os.environ["BYTEPLUS_API_KEY"]})
    try:return json.load(urllib.request.urlopen(r,timeout=120))
    except urllib.error.HTTPError as e:raise RuntimeError(f"BytePlus {e.code}: {e.read().decode()[:800]}")
def ref(name):
    p=folder_paths.get_annotated_filepath(name);x=os.path.splitext(p)[1].lower()
    if x in MIME:return {"type":"video_url","video_url":{"url":f"data:{MIME[x]};base64,"+base64.b64encode(open(p,"rb").read()).decode()},"role":"reference_video"}
    im=ImageOps.exif_transpose(Image.open(p)).convert("RGB");im.thumbnail((2048,2048));b=io.BytesIO();im.save(b,"JPEG",quality=92)
    return {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,"+base64.b64encode(b.getvalue()).decode()},"role":"reference_image"}
class SeedanceBytePlus:
    OUTPUT_NODE=True;RETURN_TYPES=();FUNCTION="run";CATEGORY="video"
    @classmethod
    def INPUT_TYPES(c):return {"required":{"prompt":("STRING",{"multiline":True}),"refs":("STRING",{"multiline":True,"tooltip":"un archivo de input por linea"}),"resolution":(["480p","720p","1080p"],{"default":"720p"}),"ratio":(["16:9","9:16","4:3","3:4","1:1","21:9"],),"duration":("INT",{"default":8,"min":4,"max":30}),"prefix":("STRING",{"default":"seedance"})}}
    @classmethod
    def IS_CHANGED(c,**k):return time.time()  # cada lanzamiento cuesta: nunca reutilizar por cache sin que se pida
    def run(self,prompt,refs,resolution,ratio,duration,prefix):
        content=[{"type":"text","text":prompt}]+[ref(n.strip()) for n in refs.splitlines() if n.strip()]
        t=call(API,{"model":"dreamina-seedance-2-5-260628","content":content,"resolution":resolution,"ratio":ratio,"duration":duration,"generate_audio":False,"watermark":False})["id"]
        print("seedance tarea",t,flush=True);fin=time.time()+1800
        while time.time()<fin:
            s=call(f"{API}/{t}")
            if s["status"]=="succeeded":break
            if s["status"] in("failed","expired","cancelled"):raise RuntimeError(json.dumps(s)[:800])
            time.sleep(10)
        else:raise RuntimeError("seedance: 30 min sin terminar, tarea "+t)
        out=f"{prefix}_{t}.mp4";urllib.request.urlretrieve(s["content"]["video_url"],os.path.join(folder_paths.get_output_directory(),out))
        return {"ui":{"text":[json.dumps({"file":out,"task":t,"usage":s.get("usage")})]}}
NODE_CLASS_MAPPINGS={"SeedanceBytePlus":SeedanceBytePlus}
