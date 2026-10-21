"""Generate deterministic Dart fixtures using the independent, supplied Python SDK."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / 'sdk/python'))
from whisklet import aeslite, bodycodec, profile

rows = []
key = profile.derive_key()
iv = bytes(range(16))
configs = {name: {} for name in bodycodec.CONFIG_KEYS}
configs['img_config'] = {'splash_img': ''}
cases = [
    ('app_config', {'code': 1, 'msg': 'app配置', 'data': configs}),
    ('video_detail', {'code': 1, 'msg': '视频详情', 'data': {'vod_info': {'vod_id': 42, 'vod_name': 'Sample', 'vod_url_with_player': []}, 'vod_history': None, 'is_collect': 0, 'comment_count': 0}}),
    ('secret_parse_api_url', {'code': 1, 'msg': '', 'data': 'A' * 800}),
]
for method, value in cases:
    plain = json.dumps(value, separators=(',', ':')).encode()
    for residue in range(16):
        lost = 10 if method == 'app_config' else 32 if method == 'video_detail' else 24
        middle = bytes([50] * residue) + iv + aeslite.cbc_encrypt(key, iv, aeslite.pkcs7_pad(plain[lost:]))
        head = bodycodec.b64e(b'0x1000x200x30')
        wire = head + bodycodec.b64e(middle) + bodycodec.b64e(('xddappsecretkey' + str(len(head))).encode())
        rows.append({'method': method, 'wire': wire, 'expected': value['data'], 'skip': residue})
    for lost in range(0, 58 if method == 'app_config' else 40 if method == 'video_detail' else 25):
        middle = iv + aeslite.cbc_encrypt(key, iv, aeslite.pkcs7_pad(plain[lost:]))
        head = bodycodec.b64e(b'0x1000x200x30')
        wire = head + bodycodec.b64e(middle) + bodycodec.b64e(('xddappsecretkey' + str(len(head))).encode())
        rows.append({'method': method, 'wire': wire, 'expected': value['data'], 'skip': 0, 'lost': lost})
target = Path('apps/mobile/test/fixtures/whisklet-vectors.json')
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(str(target), len(rows))
