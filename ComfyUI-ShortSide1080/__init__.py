"""LTX-2.5 tiled fusion mide "FullHD/HD/qHD" por el lado LARGO (1920/1280/960): un clip cuadrado saldría 1920x1920.
Aquí se mide el lado CORTO (1080/720/540): 16:9 queda igual (1920x1088), cuadrado 1088x1088, vertical 1088x1920."""
import sys

NODE_CLASS_MAPPINGS = {}


def _short_edge_ladder(m):
    def ladder(src_w, src_h, long_edge):
        s = long_edge * 9 / 16 / min(src_w, src_h)
        return m._aligned_size(*m._keep_source_if_close(src_w * s, src_h * s, src_w, src_h))
    return ladder


# ponytail: depende de nombres privados de ComfyUI-LTXVideo y de que este paquete cargue después; si LTX cambia, falla en alto (ver log)
for m in list(sys.modules.values()):
    if getattr(m, "__name__", "").endswith("tiled_fusion_sizes") and hasattr(m, "_ladder_step"):
        m._ladder_step = _short_edge_ladder(m)
        print("[ShortSide1080] tamaños medidos por lado corto")
        break
else:
    print("[ShortSide1080] AVISO: no encontré tiled_fusion_sizes, sin parchear")
