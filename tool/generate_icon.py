"""Gera o icone do app Mango com o emoticon de manga (U+1F96D).

Uso: python3 tool/generate_icon.py

Desenha com pycairo + PangoCairo (ambos disponiveis no sistema):
- fundo com cantos arredondados e gradiente laranja->amarelo (cores da manga)
- emoticon de manga centralizado (Noto Color Emoji)
- exporta o master 1024x1024 e redimensiona via cairo para todos os
  tamanhos do Android (mipmap-*), iOS (AppIcon.appiconset), web e macOS.
"""
import math
import os
import sys

import cairo

import gi
gi.require_version('Pango', '1.0')
gi.require_version('PangoCairo', '1.0')
from gi.repository import Pango, PangoCairo

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_MASTER = os.path.join(REPO, 'assets', 'icon', 'app_icon_master.png')

# Laranja da manga -> amarelo quente (topo -> base).
GRAD_TOP = (1.0, 0.62, 0.12)
GRAD_BOTTOM = (1.0, 0.82, 0.25)

EMOJI = '\U0001F96D'
EMOJI_FONT = 'Noto Color Emoji'


def draw_icon(ctx, size):
    # Fundo total (full-bleed, opaco): os launchers aplicam a propria
    # mascara de cantos. Transparencia quebraria o icone 1024 do iOS.
    grad = cairo.LinearGradient(0, 0, 0, size)
    grad.add_color_stop_rgb(0, *GRAD_TOP)
    grad.add_color_stop_rgb(1, *GRAD_BOTTOM)
    ctx.set_source(grad)
    ctx.paint()

    # Brilho sutil no topo (profundidade).
    gloss = cairo.LinearGradient(0, 0, 0, size * 0.55)
    gloss.add_color_stop_rgba(0, 1, 1, 1, 0.22)
    gloss.add_color_stop_rgba(1, 1, 1, 1, 0.0)
    ctx.set_source(gloss)
    ctx.paint()

    # Manga centralizada com respiro nas bordas (~60% do tamanho).
    layout = PangoCairo.create_layout(ctx)
    layout.set_text(EMOJI, -1)
    desc = Pango.font_description_from_string(f'{EMOJI_FONT} {int(size * 0.44)}')
    layout.set_font_description(desc)
    ctx.move_to(0, 0)
    PangoCairo.update_layout(ctx, layout)
    ink, logical = layout.get_extents()
    # Converte de unidades Pango para pixels.
    scale = 1.0 / Pango.SCALE
    ew, eh = logical.width * scale, logical.height * scale
    ix, iy = ink.x * scale, ink.y * scale
    # Centraliza pelo ink-rect (glifo colorido real, sem o espaco vazio).
    x = (size - (ink.width * scale)) / 2 - ix
    # Leve deslocamento para cima: o cabinho/folha pedem respiro embaixo.
    y = (size - (ink.height * scale)) / 2 - iy - size * 0.02
    ctx.move_to(x, y)
    PangoCairo.show_layout(ctx, layout)
    _ = (ew, eh)


def render(size):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    draw_icon(ctx, size)
    return surface


def save_surface(surface, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    surface.write_to_png(path)


def png_bytes(surface):
    """Serializa a surface em bytes PNG (para embutir no .ico)."""
    import io
    buf = io.BytesIO()
    surface.write_to_png(buf)
    return buf.getvalue()


def save_ico(sizes_to_surfaces, path):
    """Empacota PNGs como entradas de um .ico (Vista+: PNG comprimido)."""
    import struct
    os.makedirs(os.path.dirname(path), exist_ok=True)
    entries = []
    for size in sorted(sizes_to_surfaces):
        data = png_bytes(sizes_to_surfaces[size])
        entries.append((size, data))
    header = struct.pack('<HHH', 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    body = b''
    directory = b''
    for size, data in entries:
        w = 0 if size >= 256 else size
        directory += struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32,
                                 len(data), offset)
        offset += len(data)
        body += data
    with open(path, 'wb') as f:
        f.write(header + directory + body)
    print(f'  ico {sorted(sizes_to_surfaces)} -> {os.path.relpath(path, REPO)}')


def scaled(master_surface, size):
    master = master_surface.get_width()
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    ctx.scale(size / master, size / master)
    ctx.set_source_surface(master_surface, 0, 0)
    ctx.get_source().set_filter(cairo.FILTER_BEST)
    ctx.paint()
    return surface


def save_scaled(master_surface, size, path):
    surface = scaled(master_surface, size)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    surface.write_to_png(path)
    print(f'  {size}x{size} -> {os.path.relpath(path, REPO)}')


def main():
    master_size = 1024
    master = render(master_size)
    os.makedirs(os.path.dirname(OUT_MASTER), exist_ok=True)
    master.write_to_png(OUT_MASTER)
    print(f'master {master_size}x{master_size} -> {os.path.relpath(OUT_MASTER, REPO)}')

    targets = []
    # Android (mipmap-*dpi).
    for d, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                  ('xxhdpi', 144), ('xxxhdpi', 192)]:
        targets.append((px, f'android/app/src/main/res/mipmap-{d}/ic_launcher.png'))
    # iOS.
    ios_specs = [
        (40, 'Icon-App-20x20@2x.png'), (60, 'Icon-App-20x20@3x.png'),
        (29, 'Icon-App-29x29@1x.png'), (58, 'Icon-App-29x29@2x.png'),
        (87, 'Icon-App-29x29@3x.png'), (80, 'Icon-App-40x40@2x.png'),
        (120, 'Icon-App-40x40@3x.png'), (120, 'Icon-App-60x60@2x.png'),
        (180, 'Icon-App-60x60@3x.png'), (20, 'Icon-App-20x20@1x.png'),
        (40, 'Icon-App-29x29@1x.png'), (58, 'Icon-App-29x29@2x.png'),
        (40, 'Icon-App-40x40@1x.png'), (80, 'Icon-App-40x40@2x.png'),
        (76, 'Icon-App-76x76@1x.png'), (152, 'Icon-App-76x76@2x.png'),
        (167, 'Icon-App-83.5x83.5@2x.png'),
        (1024, 'Icon-App-1024x1024@1x.png'),
    ]
    for px, name in ios_specs:
        targets.append((px, f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}'))
    # Web + favicon.
    for px, name in [(192, 'web/icons/Icon-192.png'),
                     (512, 'web/icons/Icon-512.png'),
                     (192, 'web/icons/Icon-maskable-192.png'),
                     (512, 'web/icons/Icon-maskable-512.png'),
                     (32, 'web/favicon.png')]:
        targets.append((px, name))
    # Windows (ico via png: flutter usa app_icon.ico; mantemos png 256 + ico).
    targets.append((256, 'windows/runner/resources/app_icon.png'))
    # macOS.
    for px, name in [(16, 'app_icon_16.png'), (32, 'app_icon_32.png'),
                     (64, 'app_icon_64.png'), (128, 'app_icon_128.png'),
                     (256, 'app_icon_256.png'), (512, 'app_icon_512.png'),
                     (1024, 'app_icon_1024.png')]:
        targets.append((px, f'macos/Runner/Assets.xcassets/AppIcon.appiconset/{name}'))

    for px, rel in targets:
        save_scaled(master, px, os.path.join(REPO, rel))

    # Windows .ico (16/32/48/256): Runner.rc aponta para app_icon.ico.
    ico_sizes = {s: scaled(master, s) for s in (16, 32, 48, 256)}
    save_ico(ico_sizes, os.path.join(REPO, 'windows/runner/resources/app_icon.ico'))

    # Linux: icone do app (usado pelo .desktop/empacotamento).
    save_scaled(master, 512, os.path.join(REPO, 'assets/icon/app_icon_linux.png'))


if __name__ == '__main__':
    sys.exit(main())
