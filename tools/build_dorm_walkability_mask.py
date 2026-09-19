"""生成宿舍内部的「可站立」掩膜：assets/town/dorm_walkable_mask.png

思路
----
宿舍底图 `assets/town/dorm_slow_life.jpg` 是一张俯视剖视图，没有碰撞数据。
玩家要在里面自己走到门口，所以需要知道"哪块是地面"。这里用两条规则叠出来：

1. **地板色分类**：木地板有一套固定的暖木色（R≈215~235 / G≈150~175 / B≈70~105），
   按色差阈值判定 + 形态学去噪 → 得到"看起来是地面"的像素。
2. **区域白名单**：底图外侧的人行道、以及左侧餐厅那一堆家具，颜色和地板撞车会误判。
   所以再用一组矩形把可行走范围框死（大厅 / 门厅 / 玩家卧室门口 / 左侧餐厅），
   并把家具的误判矩形减掉。

输出是黑白 PNG（白=可站），运行时按 `image_pos * MASK_SCALE` 采样。
图片改版后重跑本脚本即可（`python tools/build_dorm_walkability_mask.py`）。
"""
from PIL import Image, ImageFilter, ImageDraw
import collections
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "town", "dorm_slow_life.jpg")
DST = os.path.join(ROOT, "assets", "town", "dorm_walkable_mask.png")

# 木地板的样板色（在底图上采样得到）
FLOOR_SAMPLES = [
    (223, 160, 91), (217, 160, 73), (233, 171, 96), (222, 162, 100),
    (224, 166, 82), (223, 162, 95), (228, 170, 100), (215, 155, 85),
    (210, 150, 80), (235, 175, 105),
]
FLOOR_TOLERANCE = 24

# 可行走白名单（底图像素坐标，1448x1086）
REGIONS = [
    (628, 378, 852, 604),   # 大厅：书架前那片开阔木地板
    (852, 378, 962, 442),   # 大厅东侧过道
    (632, 592, 764, 674),   # 门厅：两盆绿植之间、直到蓝色双开门
    (712, 288, 762, 390),   # 玩家卧室门口（书架之间的那道缝）
    (160, 336, 630, 668),   # 左侧餐厅 / 桌游区
]
# 颜色与地板撞车、但其实是家具的地方，直接挖掉
BLOCKERS = [
    (628, 296, 724, 380),   # 大厅西侧书架（浅木色顶框）
    (796, 296, 892, 380),   # 大厅东侧书架
    (156, 386, 200, 630),   # 左侧靠墙书架
    (222, 378, 354, 464),   # 左上餐桌
    (222, 526, 354, 624),   # 左下餐桌
    (398, 468, 530, 564),   # 中间棋牌桌
    (444, 292, 532, 336),   # 地毯上的圆桌
    (174, 292, 336, 340),   # 左上厨台
    (176, 616, 440, 668),   # 左下门口的白色地垫/柜子
]
# 地板色判不出来、但确实是地面的补丁（门槛在门的投影下面，颜色偏暗）
PATCHES = [
    (636, 598, 762, 672),   # 门槛
    (724, 288, 762, 386),   # 玩家卧室门口那道缝（地板被门帘压暗，颜色判不出来）
]
MASK_SCALE = 0.5


def near(color, palette, tol):
    r, g, b = color
    return any(abs(r - pr) <= tol and abs(g - pg) <= tol and abs(b - pb) <= tol
               for pr, pg, pb in palette)


def main() -> None:
    image = Image.open(SRC).convert("RGB")
    width, height = image.size
    source = image.load()

    raw = Image.new("L", (width, height), 0)
    raw_pixels = raw.load()
    for y in range(height):
        for x in range(width):
            if near(source[x, y], FLOOR_SAMPLES, FLOOR_TOLERANCE):
                raw_pixels[x, y] = 255
    # 先腐蚀 2px 去掉地板纹理上的孤点，再膨胀 3px 补回家具投下的细缝
    cleaned = raw.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(7))

    # 只保留建筑里的连通块（外侧人行道同样是暖色，但会被白名单挡掉，这里再兜一层）
    kept = Image.new("L", (width, height), 0)
    kept_pixels = kept.load()
    seen = [[False] * width for _ in range(height)]
    cleaned_pixels = cleaned.load()
    for y0 in range(90, 700):
        for x0 in range(130, 1270):
            if seen[y0][x0] or not cleaned_pixels[x0, y0]:
                continue
            queue = collections.deque([(x0, y0)])
            seen[y0][x0] = True
            component = []
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < width and 0 <= ny < height and not seen[ny][nx] and cleaned_pixels[nx, ny]:
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            if len(component) >= 1200:
                for x, y in component:
                    kept_pixels[x, y] = 255

    final = Image.new("L", (width, height), 0)
    final_pixels = final.load()
    clipped = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(clipped)
    for rect in REGIONS:
        draw.rectangle(list(rect), fill=255)
    clipped_pixels = clipped.load()
    for y in range(height):
        for x in range(width):
            if kept_pixels[x, y] and clipped_pixels[x, y]:
                final_pixels[x, y] = 255
    draw = ImageDraw.Draw(final)
    for rect in PATCHES:
        draw.rectangle(list(rect), fill=255)
    for rect in BLOCKERS:
        draw.rectangle(list(rect), fill=0)

    small = final.resize((int(width * MASK_SCALE), int(height * MASK_SCALE)), Image.LANCZOS)
    small = small.point(lambda value: 255 if value > 127 else 0)
    small.save(DST)

    walkable = sum(1 for y in range(height) for x in range(width) if final_pixels[x, y])
    print("source      :", SRC, image.size)
    print("mask saved  :", DST, small.size)
    print("walkable px :", walkable, "(%.2f%% of image)" % (walkable * 100.0 / (width * height)))


if __name__ == "__main__":
    main()
