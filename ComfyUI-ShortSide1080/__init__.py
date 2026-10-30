"""LTX-2.5 tiled fusion mide "FullHD/HD/qHD" por el lado LARGO (1920/1280/960): un clip cuadrado saldría 1920x1920.
Aquí se mide el lado CORTO (1080/720/540): 16:9 queda igual (1920x1088), cuadrado 1088x1088, vertical 1088x1920."""
import sys, threading, time


class ClipColorMatch:
    """Un solo ajuste (media y contraste por canal) calculado sobre todo el clip: igual en cada fotograma, no parpadea."""
    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "match"
    CATEGORY = "image/color"

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"images": ("IMAGE",), "reference": ("IMAGE",)}}

    def match(self, images, reference):
        dims = (0, 1, 2)
        m, st = images.mean(dims, keepdim=True), images.std(dims, keepdim=True).clamp_min(1e-5)
        rm, rst = reference.to(images.device).mean(dims, keepdim=True), reference.to(images.device).std(dims, keepdim=True)
        return (((images - m) * rst / st + rm).clamp(0, 1),)


NODE_CLASS_MAPPINGS = {"ClipColorMatch": ClipColorMatch}


def _short_edge_ladder(m):
    def ladder(src_w, src_h, long_edge):
        s = long_edge * 9 / 16 / min(src_w, src_h)
        return m._aligned_size(*m._keep_source_if_close(src_w * s, src_h * s, src_w, src_h))
    return ladder


def _patch():  # ComfyUI no garantiza el orden de carga: se espera a que LTX esté importado
    for _ in range(300):
        for m in list(sys.modules.values()):
            if getattr(m, "__name__", "").endswith("tiled_fusion_sizes") and hasattr(m, "_ladder_step"):
                m._ladder_step = _short_edge_ladder(m)
                print("[ShortSide1080] tamaños medidos por lado corto")
                return
        time.sleep(1)
    print("[ShortSide1080] AVISO: no encontré tiled_fusion_sizes, sin parchear")


# ponytail: depende de nombres privados de ComfyUI-LTXVideo; si LTX cambia, avisa en el log y queda el lado largo
threading.Thread(target=_patch, daemon=True).start()
