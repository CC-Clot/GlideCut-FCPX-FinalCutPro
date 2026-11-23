#!/usr/bin/env python3
"""像素级判定 FCP 时间线是否真的平移。

判据：
- 静止基线差异（base_1 vs base_2/3）：画面自身噪点/动画造成的差异，作为"噪音基线"。
- 操作后差异（base_3 vs after_1/2/3）：设值/滚动 action 造成的差异。
- 若操作后差异 >> 噪音基线（例如 5 倍以上且绝对像素占比明显），判定"画面真的动了"。
"""
import sys, os, json
from PIL import Image, ImageChops, ImageStat

DIR = "/tmp/pan_verify"

# 读取 FCP 主窗口区域裁剪框
crop_path = os.path.join(DIR, "crop.json")
box = None
if os.path.exists(crop_path):
    with open(crop_path) as f:
        c = json.load(f)
    x, y, w, h = c["x"], c["y"], c["w"], c["h"]
    box = (x, y, x + w, y + h)
    print(f"裁剪到 FCP 窗口区域: {box}")

def load(name):
    p = os.path.join(DIR, name + ".png")
    if not os.path.exists(p):
        print(f"缺少截图: {p}")
        sys.exit(1)
    img = Image.open(p).convert("RGB")
    if box:
        img = img.crop(box)
    return img

def diff_ratio(a, b, threshold=18):
    """返回差异像素占比（0~1）与平均差异强度。threshold 过滤轻微压缩噪点。"""
    if a.size != b.size:
        return None, None, f"尺寸不同 {a.size} vs {b.size}"
    d = ImageChops.difference(a, b)
    gray = d.convert("L")
    # 统计差异超过阈值的像素
    hist = gray.histogram()
    total = sum(hist)
    over = sum(hist[threshold:])
    ratio = over / total if total else 0
    mean = ImageStat.Stat(gray).mean[0]
    return ratio, mean, None

base1, base2, base3 = load("base_1"), load("base_2"), load("base_3")
a1, a2, a3 = load("after_1"), load("after_2"), load("after_3")

print(f"画面尺寸: {base1.size}")

# 静止基线
b_ratios, b_means = [], []
for x, y in [(base1, base2), (base2, base3), (base1, base3)]:
    r, m, err = diff_ratio(x, y)
    if err:
        print("基线对比错误:", err); sys.exit(1)
    b_ratios.append(r); b_means.append(m)
    print(f"静止基线差异: 像素占比={r*100:.3f}%  平均强度={m:.3f}")

baseline = max(b_ratios)
baseline_mean = max(b_means)

# 操作后（用最后一张基线 vs 每张操作后）
o_ratios, o_means = [], []
for img in [a1, a2, a3]:
    r, m, err = diff_ratio(base3, img)
    if err:
        print("操作对比错误:", err); sys.exit(1)
    o_ratios.append(r); o_means.append(m)
    print(f"操作后差异:   像素占比={r*100:.3f}%  平均强度={m:.3f}")

op = max(o_ratios)
op_mean = max(o_means)

print("")
print("=" * 50)
# 判定
if op < 0.005 and op_mean < baseline_mean * 1.5:
    print("结论: 画面【没有】平移 —— 操作前后像素几乎一致（AX 设值/action 未驱动视图）")
    verdict = "NO_MOVE"
elif op > max(baseline * 3, 0.01) and op_mean > baseline_mean * 2:
    print("结论: 画面【确实】平移了 —— 操作后差异显著大于静止基线")
    verdict = "MOVED"
else:
    print("结论: 无法明确判定（差异介于噪音与信号之间），建议换更长的测试项目再测")
    verdict = "UNCLEAR"

print(f"判定码: {verdict}")
print(f"操作差异/基线差异 = {op/baseline if baseline > 0 else float('inf'):.2f}x")
